import Darwin
import Foundation
import ViftyCore

public enum HelperMaintenanceAuthorityStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidReceipt(String)
    case unsafePath(String)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReceipt(let reason):
            "Invalid helper-maintenance authority receipt: \(reason)"
        case .unsafePath(let reason):
            "Unsafe helper-maintenance authority path: \(reason)"
        case .ioFailure(let reason):
            "Helper-maintenance authority I/O failed: \(reason)"
        }
    }
}

/// Stores the daemon's final maintenance authorization in a fixed privileged
/// location. The lifecycle worker independently verifies the same ownership,
/// mode, schema, expiry, and operation constraints before destructive cleanup.
public final class HelperMaintenanceAuthorityStore: @unchecked Sendable {
    public static let defaultDirectoryURL = URL(
        fileURLWithPath: "/Library/Application Support/Vifty/Maintenance",
        isDirectory: true
    )
    public static let authorityFileName = "authorized-v1.json"
    public static let claimedAuthorityFileName = "claimed-v1.json"
    public static let maximumReceiptBytes = 64 * 1_024

    public let directoryURL: URL
    public let authorityURL: URL
    private let requiredOwnerID: uid_t
    private let operationLock = NSLock()
    private var anchoredDirectory: SecureStorageDirectory?

    public init(
        directoryURL: URL = HelperMaintenanceAuthorityStore.defaultDirectoryURL,
        requiredOwnerID: uid_t = 0
    ) {
        self.directoryURL = directoryURL
        self.authorityURL = directoryURL.appendingPathComponent(Self.authorityFileName)
        self.requiredOwnerID = requiredOwnerID
    }

    public func save(_ receipt: HelperMaintenanceAuthorityReceipt) throws {
        try Self.validate(receipt)
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: true) else {
                    throw HelperMaintenanceAuthorityStoreError.ioFailure(
                        "could not create the privileged maintenance directory"
                    )
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                encoder.outputFormatting = [.sortedKeys]
                let data: Data
                do {
                    data = try encoder.encode(receipt)
                } catch {
                    throw HelperMaintenanceAuthorityStoreError.invalidReceipt(
                        error.localizedDescription
                    )
                }
                try directory.replaceRegularFile(
                    named: Self.authorityFileName,
                    data: data,
                    maximumBytes: Self.maximumReceiptBytes
                )
            }
        }
    }

    public func load() throws -> HelperMaintenanceAuthorityReceipt? {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false),
                      let data = try directory.readRegularFile(
                        named: Self.authorityFileName,
                        maximumBytes: Self.maximumReceiptBytes
                      ) else {
                    return nil
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let receipt: HelperMaintenanceAuthorityReceipt
                do {
                    receipt = try decoder.decode(HelperMaintenanceAuthorityReceipt.self, from: data)
                } catch {
                    throw HelperMaintenanceAuthorityStoreError.invalidReceipt(
                        error.localizedDescription
                    )
                }
                try Self.validate(receipt)
                return receipt
            }
        }
    }

    public func clear() throws {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false) else {
                    return
                }
                _ = try directory.removeRegularFile(named: Self.authorityFileName)
                _ = try directory.removeRegularFile(named: Self.claimedAuthorityFileName)
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

    private static func validate(_ receipt: HelperMaintenanceAuthorityReceipt) throws {
        guard receipt.schemaVersion == HelperMaintenanceAuthorityReceipt.currentSchemaVersion,
              receipt.schemaID == HelperMaintenanceAuthorityReceipt.schemaID,
              receipt.recordKind == HelperMaintenanceAuthorityReceipt.recordKind,
              receipt.operation == .repair || receipt.operation == .uninstall,
              !receipt.tokenID.isEmpty,
              receipt.tokenIssuedAt <= receipt.authorizedAt,
              receipt.authorizedAt <= receipt.expiresAt,
              !receipt.bootSessionID.isEmpty,
              !receipt.daemonSessionID.isEmpty,
              receipt.expectedFanIDs == Array(Set(receipt.expectedFanIDs)).sorted(),
              !receipt.expectedFanIDs.isEmpty,
              receipt.expectedFanIDs.allSatisfy(SMCFanControlKeys.isValidFanID),
              receipt.helperSHA256.count == 64,
              receipt.helperSHA256.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (97...102).contains($0.value)
              }),
              receipt.quiesced,
              receipt.tokenConsumed else {
            throw HelperMaintenanceAuthorityStoreError.invalidReceipt(
                "schema, binding, fan-set, digest, or quiescence fields are invalid"
            )
        }
    }

    private func mapStorageErrors<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as HelperMaintenanceAuthorityStoreError {
            throw error
        } catch let error as SecureStorageError {
            switch error {
            case .invalidPath(let reason), .unsafePath(let reason):
                throw HelperMaintenanceAuthorityStoreError.unsafePath(reason)
            case .fileTooLarge(_, let maximumBytes):
                throw HelperMaintenanceAuthorityStoreError.invalidReceipt(
                    "encoded size exceeds \(maximumBytes) bytes"
                )
            case .ioFailure(let reason):
                throw HelperMaintenanceAuthorityStoreError.ioFailure(reason)
            }
        } catch {
            throw HelperMaintenanceAuthorityStoreError.ioFailure(error.localizedDescription)
        }
    }
}
