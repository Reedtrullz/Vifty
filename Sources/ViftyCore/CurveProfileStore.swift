import Darwin
import Foundation

enum CurveProfileBackupStage: CaseIterable, Equatable, Sendable {
    case copy
    case permissions
    case synchronize
    case rename
}

struct CurveProfileBackupHooks: Sendable {
    var beforeStage: @Sendable (CurveProfileBackupStage) throws -> Void
    var synchronize: @Sendable (Int32) throws -> Void

    static let live = CurveProfileBackupHooks(
        beforeStage: { _ in },
        synchronize: { descriptor in
            guard fsync(descriptor) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    )
}

public enum CurveProfileLoadSource: String, Equatable, Sendable {
    case primary
    case recoveredBackup
    case empty
}

public struct CurveProfileLoadResult: Equatable, Sendable {
    public var profiles: [CurveProfile]
    public var source: CurveProfileLoadSource
    public var recoveryMessage: String?

    public init(
        profiles: [CurveProfile],
        source: CurveProfileLoadSource,
        recoveryMessage: String? = nil
    ) {
        self.profiles = profiles
        self.source = source
        self.recoveryMessage = recoveryMessage
    }
}

public enum CurveProfileStoreError: Error, Equatable, LocalizedError {
    case noValidProfileData(primary: String, backup: String)

    public var errorDescription: String? {
        switch self {
        case .noValidProfileData(let primary, let backup):
            "Curve profiles and backup are unreadable (primary: \(primary); backup: \(backup))."
        }
    }
}

public final class CurveProfileStore: @unchecked Sendable {
    private let url: URL
    private let backupHooks: CurveProfileBackupHooks
    private let cleanupDirectoryURL: URL?

    private var backupURL: URL {
        url.appendingPathExtension("bak")
    }

    public init(url: URL? = nil) {
        let resolvedURL = url ?? Self.defaultURL()
        self.url = resolvedURL
        self.backupHooks = .live
        self.cleanupDirectoryURL = url == nil && Self.isRunningUnderXCTest
            ? resolvedURL.deletingLastPathComponent()
            : nil
    }

    init(url: URL, backupHooks: CurveProfileBackupHooks) {
        self.url = url
        self.backupHooks = backupHooks
        self.cleanupDirectoryURL = nil
    }

    var storageURL: URL { url }

    deinit {
        if let cleanupDirectoryURL {
            try? FileManager.default.removeItem(at: cleanupDirectoryURL)
        }
    }

    public func load() -> [CurveProfile] {
        (try? loadResult().profiles) ?? []
    }

    public func loadResult() throws -> CurveProfileLoadResult {
        let primary = decodeProfiles(at: url)
        switch primary {
        case .success(let profiles):
            return CurveProfileLoadResult(profiles: profiles, source: .primary)
        case .missing, .failure:
            break
        }

        switch decodeProfiles(at: backupURL) {
        case .success(let profiles):
            let message: String
            switch primary {
            case .missing:
                message = "The primary curve-profile file was missing; Vifty loaded its private backup."
            case .failure(let reason):
                message = "The primary curve-profile file was unreadable (\(reason)); Vifty loaded its private backup."
            case .success:
                preconditionFailure("Primary success returned before backup recovery.")
            }
            return CurveProfileLoadResult(
                profiles: profiles,
                source: .recoveredBackup,
                recoveryMessage: message
            )
        case .missing:
            if case .missing = primary {
                return CurveProfileLoadResult(profiles: [], source: .empty)
            }
            throw CurveProfileStoreError.noValidProfileData(
                primary: primary.failureDescription,
                backup: "missing"
            )
        case .failure(let backupReason):
            throw CurveProfileStoreError.noValidProfileData(
                primary: primary.failureDescription,
                backup: backupReason
            )
        }
    }

    public func save(_ profiles: [CurveProfile]) {
        try? saveThrowing(profiles)
    }

    public func saveThrowing(_ profiles: [CurveProfile]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let attr: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o700)]
        try FileManager.default.setAttributes(attr, ofItemAtPath: directory.path)

        // Only validated primary bytes may replace a known-good backup. A
        // corrupt primary must never destroy the last recoverable copy.
        if case .success = decodeProfiles(at: url),
           let primaryData = try? Data(contentsOf: url) {
            replaceBackupIfPossible(with: primaryData)
        }

        let data = try JSONEncoder().encode(profiles)
        try data.write(to: url, options: .atomic)
        try restrictFilePermissions(at: url)

        // Ensure there is a valid recovery copy. Replacement is sibling-temp
        // plus rename, so an immutable or otherwise unwritable old backup is
        // left byte-for-byte intact when replacement fails.
        if case .success = decodeProfiles(at: backupURL) {
            try? restrictFilePermissions(at: backupURL)
        } else {
            replaceBackupIfPossible(with: data)
        }
    }

    private func replaceBackupIfPossible(with data: Data) {
        let temporaryURL = backupURL.deletingLastPathComponent().appendingPathComponent(
            ".\(backupURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try backupHooks.beforeStage(.copy)
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try backupHooks.beforeStage(.permissions)
            try restrictFilePermissions(at: temporaryURL)
            try backupHooks.beforeStage(.synchronize)
            try synchronizeFile(at: temporaryURL)
            try backupHooks.beforeStage(.rename)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    backupURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: backupURL)
            }
            try restrictFilePermissions(at: backupURL)
        } catch {
            // Backups are best-effort; saving the primary profile file is what
            // should report success or failure to the caller.
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    private func synchronizeFile(at fileURL: URL) throws {
        let descriptor = open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        try backupHooks.synchronize(descriptor)
    }

    private enum DecodeResult {
        case success([CurveProfile])
        case missing
        case failure(String)

        var failureDescription: String {
            switch self {
            case .success: "valid"
            case .missing: "missing"
            case .failure(let reason): reason
            }
        }
    }

    private func decodeProfiles(at fileURL: URL) -> DecodeResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            return .success(try JSONDecoder().decode([CurveProfile].self, from: data))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func restrictFilePermissions(at url: URL) throws {
        let attr: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o600)]
        try FileManager.default.setAttributes(attr, ofItemAtPath: url.path)
    }

    private static func defaultURL() -> URL {
        if isRunningUnderXCTest {
            return FileManager.default
                .temporaryDirectory
                .appendingPathComponent("vifty-curve-profiles-xctest")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("curve-profiles.json")
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/curve-profiles.json")
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }
}
